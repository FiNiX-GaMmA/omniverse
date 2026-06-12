import SwiftUI
import UIKit
import AVFoundation
import CoreImage.CIFilterBuiltins

/// Server-less cross-device login (see SYNC_SPEC.md).
/// A single text string `OMNIVERSE-SYNC1:<base64(utf8(json))>` carries the full
/// credential + settings bundle, byte-identical across iOS & Android.
enum SyncPayload {
    static let prefix = "OMNIVERSE-SYNC1:"

    /// Builds the sync string from credentials + settings. Empty fields are omitted.
    static func buildSyncString(credentials c: ApiCredentials, settings: UserSettings) -> String {
        var json: [String: Any] = ["v": 1]
        func put(_ key: String, _ value: String) {
            let t = value.trimmed
            if !t.isEmpty { json[key] = t }
        }
        put("trakt_access_token", c.traktAccessToken)
        put("trakt_refresh_token", c.traktRefreshToken)
        if c.traktTokenExpiresAt != 0 { json["trakt_token_expires_at"] = c.traktTokenExpiresAt }
        put("trakt_username", c.traktUsername)
        put("trakt_client_id", c.traktClientId)
        put("trakt_client_secret", c.traktClientSecret)
        put("tmdb_token", c.tmdbToken)
        put("tvdb_api_key", c.tvdbApiKey)
        put("tvdb_pin", c.tvdbPin)
        put("pixeldrain_api_key", c.pixeldrainApiKey)
        // NOTE: the long AniList JWT and the settings object are intentionally
        // NOT in the QR — they push it past a scannable density. After scanning,
        // the Trakt tokens above let the device pull the AniList token, settings,
        // watch history and watchlist from the cloud backup automatically.

        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return prefix }
        return prefix + data.base64EncodedString()
    }

    /// Parses a sync string into a credentials patch + optional settings.
    /// Returns nil if the prefix is missing or the payload can't be decoded.
    static func parseSyncString(_ s: String) -> (credentials: ApiCredentials, settings: UserSettings?)? {
        let trimmed = s.trimmed
        guard trimmed.hasPrefix(prefix) else { return nil }
        let b64 = String(trimmed.dropFirst(prefix.count)).trimmed
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var c = ApiCredentials()
        if let v = obj["trakt_access_token"] as? String { c.traktAccessToken = v }
        if let v = obj["trakt_refresh_token"] as? String { c.traktRefreshToken = v }
        if let v = obj["trakt_token_expires_at"] as? Int { c.traktTokenExpiresAt = v }
        if let v = obj["trakt_username"] as? String { c.traktUsername = v }
        if let v = obj["trakt_client_id"] as? String { c.traktClientId = v }
        if let v = obj["trakt_client_secret"] as? String { c.traktClientSecret = v }
        if let v = obj["tmdb_token"] as? String { c.tmdbToken = v }
        if let v = obj["tvdb_api_key"] as? String { c.tvdbApiKey = v }
        if let v = obj["tvdb_pin"] as? String { c.tvdbPin = v }
        if let v = obj["pixeldrain_api_key"] as? String { c.pixeldrainApiKey = v }
        if let v = obj["anilist_access_token"] as? String { c.anilistAccessToken = v }

        let settings = (obj["settings"] as? [String: Any]).map { UserSettings.fromJSON($0) }
        return (c, settings)
    }

    /// Renders a QR (error correction "M") for the given string.
    static func qrImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        // "L" = lowest error correction = fewest modules for the same data =
        // least dense = easiest for a phone camera to scan off a screen.
        filter.correctionLevel = "L"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Camera QR scanner

/// Live camera QR scanner over AVCaptureSession. Calls `onScan` once with the
/// first decoded `.qr` payload, then stops the session.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    func makeUIViewController(context: Context) -> ScannerController {
        let vc = ScannerController()
        vc.coordinator = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onScan: (String) -> Void
        private var didScan = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  obj.type == .qr, let value = obj.stringValue else { return }
            didScan = true
            DispatchQueue.main.async { self.onScan(value) }
        }
    }

    final class ScannerController: UIViewController {
        weak var coordinator: Coordinator?
        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configure()
        }

        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            previewLayer = preview
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.stopRunning() }
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.bounds
        }
    }
}

// MARK: - Scan sheet (camera + paste fallback)

/// Full-screen camera scanner sheet with a "Paste code" fallback.
struct SyncScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void
    @State private var showPaste = false
    @State private var pasted = ""
    @State private var cameraPermissionGranted = false
    @State private var cameraPermissionChecked = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if cameraPermissionGranted {
                    QRScannerView { value in
                        onScan(value)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else if cameraPermissionChecked {
                    VStack(spacing: 16) {
                        Text("Camera access is required to scan the Sync QR code.")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(LiquidColors.cyan)
                    }
                } else {
                    ProgressView()
                        .tint(.white)
                }

                VStack {
                    Spacer()
                    if cameraPermissionGranted {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(LiquidColors.cyan.opacity(0.9), lineWidth: 3)
                            .frame(width: 240, height: 240)
                            .shadow(color: LiquidColors.cyan.opacity(0.4), radius: 16)
                    }
                    Spacer()
                    Text("Point the camera at a Sync QR")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Button { showPaste = true } label: {
                        Label("Paste code", systemImage: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Scan Sync QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .onAppear { checkCameraPermission() }
            .sheet(isPresented: $showPaste) {
                NavigationStack {
                    ZStack {
                        LiquidColors.ink.ignoresSafeArea()
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Paste sync code")
                                .font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                            Text("Paste an OMNIVERSE-SYNC1 code (or a trakt.tv activation URL) copied from another device.")
                                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                            TextEditor(text: $pasted)
                                .frame(height: 160)
                                .foregroundStyle(.white)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            Button {
                                let v = pasted
                                showPaste = false
                                onScan(v)
                                dismiss()
                            } label: { Text("Import").frame(maxWidth: .infinity) }
                                .buttonStyle(AccentButtonStyle())
                            Spacer()
                        }
                        .padding(24)
                    }
                    .navigationTitle("Paste code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { showPaste = false } } }
                }
                .preferredColorScheme(.dark)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermissionGranted = true
            cameraPermissionChecked = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    cameraPermissionGranted = granted
                    cameraPermissionChecked = true
                }
            }
        case .denied, .restricted:
            cameraPermissionGranted = false
            cameraPermissionChecked = true
        @unknown default:
            cameraPermissionGranted = false
            cameraPermissionChecked = true
        }
    }
}

// MARK: - Show sync QR sheet

/// Renders the current device's sync bundle as a large QR on a white card.
struct SyncQRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state
    // Computed from live state at render time (avoids stale/empty @State capture
    // that produced an unscannable "empty" QR).
    private var syncString: String { state.buildSyncString() }

    var body: some View {
        ZStack {
            LiquidColors.ink.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Show Sync QR").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text("Scan this with \"Scan Sync QR\" on another device to instantly sign in to every service and copy your preferences. No network required.")
                        .font(.system(size: 14)).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    if let img = SyncPayload.qrImage(from: syncString) {
                        Image(uiImage: img)
                            .interpolation(.none).resizable()
                            .frame(width: 340, height: 340)
                            .padding(20)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    } else {
                        Text("Could not generate QR.").foregroundStyle(.red)
                    }
                    Button("Copy code") { UIPasteboard.general.string = syncString }
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                }
                .padding(28)
            }
        }
        .preferredColorScheme(.dark)
    }
}
