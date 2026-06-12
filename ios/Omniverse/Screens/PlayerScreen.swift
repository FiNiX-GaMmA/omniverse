import SwiftUI
import AVKit
import AVFoundation
import UIKit

/// AVAsset resource-loader delegate that accepts server-trust (TLS) challenges,
/// so AVPlayer can play streams whose certs are self-signed / mismatched
/// (Pixeldrain, GameDrive bypass proxy, some VidSrc CDNs). This is the only
/// supported hook for AVPlayer cert handling — AVFoundation does its own TLS
/// and ignores the app's URLSession trust override.
final class PermissiveAssetTrust: NSObject, AVAssetResourceLoaderDelegate {
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForResponseTo authenticationChallenge: URLAuthenticationChallenge) -> Bool {
        let space = authenticationChallenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = space.serverTrust {
            authenticationChallenge.sender?.use(URLCredential(trust: trust), for: authenticationChallenge)
            return true
        }
        authenticationChallenge.sender?.performDefaultHandling?(for: authenticationChallenge)
        return false
    }
}

// MARK: - Orientation lock helper
//
// Ported from the Flutter players' `SystemChrome.setPreferredOrientations`
// calls. On iOS 16+ we ask the active window scene to update its geometry to
// landscape while the player is on screen and revert on disappear. The app's
// `AppDelegate`/`supportedInterfaceOrientationsFor` is not part of this
// contract, so we drive it via the scene API directly.
enum PlayerOrientation {
    /// Tracks the orientations the app should currently allow. An AppDelegate
    /// (outside this file) may read this if it implements
    /// `application(_:supportedInterfaceOrientationsFor:)`.
    static var lockMask: UIInterfaceOrientationMask = .all

    static func forceLandscape() {
        lockMask = .landscape
        apply(.landscapeRight)
    }

    static func restore() {
        lockMask = .all
        apply(nil)
    }

    private static func apply(_ orientation: UIInterfaceOrientation?) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let mask: UIInterfaceOrientationMask
        switch orientation {
        case .landscapeRight, .landscapeLeft: mask = .landscape
        default: mask = .all
        }
        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: mask)
        scene.requestGeometryUpdate(prefs) { _ in }
        scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

// MARK: - Skip interval model (AniSkip)

private struct SkipInterval {
    let type: String   // "op", "ed", "recap"
    let startMs: Int
    let endMs: Int
}

// MARK: - AniSkip API (ported 1:1 from `_AniSkipApi`)

private enum AniSkipApi {
    static func fetch(anilistId: Int, episode: Int, episodeLengthSec: Int) async -> [SkipInterval] {
        // 1. /v2/ with actual episode duration
        if let u = URL(string: "https://api.aniskip.com/v2/skip-times/\(anilistId)/\(episode)?types[]=op&types[]=ed&types[]=recap&episodeLength=\(episodeLengthSec)") {
            let list = await fetchUri(u)
            if !list.isEmpty { return list }
        }
        // Fallback 1: /v2/ with standard episode length 1440
        if let u = URL(string: "https://api.aniskip.com/v2/skip-times/\(anilistId)/\(episode)?types[]=op&types[]=ed&types[]=recap&episodeLength=1440") {
            let listV2 = await fetchUri(u)
            if !listV2.isEmpty { return listV2 }
        }
        // Fallback 2: /v1/ (no episode length, only op/ed)
        if let u = URL(string: "https://api.aniskip.com/v1/skip-times/\(anilistId)/\(episode)?types=op&types=ed") {
            return await fetchUri(u)
        }
        return []
    }

    private static func fetchUri(_ uri: URL) async -> [SkipInterval] {
        do {
            let r = try await Http.shared.request(uri, headers: ["Accept": "application/json"], timeout: 4)
            guard r.status == 200 else { return [] }
            let body = try JSONSerialization.jsonObject(with: r.data)
            guard let map = body as? [String: Any], (map["found"] as? Bool) == true,
                  let results = map["results"] as? [Any] else { return [] }
            var intervals: [SkipInterval] = []
            for entry in results {
                guard let e = entry as? [String: Any] else { continue }
                guard let interval = e["interval"] as? [String: Any] else { continue }
                let type = (e["skipType"] ?? e["skip_type"]).flatMap { $0 as? String }
                guard let type else { continue }
                let startNum = (interval["startTime"] ?? interval["start_time"])
                let endNum = (interval["endTime"] ?? interval["end_time"])
                let start = (startNum as? Double) ?? (startNum as? Int).map(Double.init)
                let end = (endNum as? Double) ?? (endNum as? Int).map(Double.init)
                guard let start, let end, end > start else { continue }
                intervals.append(SkipInterval(type: type,
                                               startMs: Int((start * 1000).rounded()),
                                               endMs: Int((end * 1000).rounded())))
            }
            return intervals
        } catch {
            return []
        }
    }
}

// MARK: - Caption model + parsing (.ass/.vtt/.srt — ported from _parseCaptions)

private struct CaptionCue {
    let startMs: Int
    let endMs: Int
    let text: String
}

private enum CaptionParser {
    static func parse(_ contents: String) -> [CaptionCue] {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Split on blank-line boundaries (\n\s*\n) using a regex, then operate
        // on the resulting blocks. We insert a sentinel and split on it.
        let sentinel = "\u{0001}OMNI_BLOCK\u{0001}"
        let withSentinels = normalized.replacingOccurrences(
            of: "\\n\\s*\\n", with: sentinel, options: .regularExpression)
        let blocks = withSentinels.components(separatedBy: sentinel)
        var cues: [CaptionCue] = []
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }),
                  timeIndex != lines.count - 1 else { continue }
            guard let range = captionRange(lines[timeIndex]) else { continue }
            let text = lines[(timeIndex + 1)...]
                .joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
                // Strip basic .ass override tags like {\an8}
                .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            cues.append(CaptionCue(startMs: range.0, endMs: range.1, text: text))
        }
        return cues
    }

    private static func captionRange(_ line: String) -> (Int, Int)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        guard let start = captionTime(parts[0]) else { return nil }
        let endRaw = parts[1].split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? parts[1]
        guard let end = captionTime(endRaw), end > start else { return nil }
        return (start, end)
    }

    /// Returns milliseconds.
    private static func captionTime(_ value: String) -> Int? {
        let clean = value.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let pieces = clean.components(separatedBy: ":")
        guard pieces.count >= 2, pieces.count <= 3 else { return nil }
        let secondsPart = pieces[pieces.count - 1].components(separatedBy: ".")
        guard let seconds = Int(secondsPart[0]) else { return nil }
        var millis = 0
        if secondsPart.count > 1 {
            let padded = secondsPart[1].padding(toLength: 3, withPad: "0", startingAt: 0)
            millis = Int(padded.prefix(3)) ?? 0
        }
        guard let minutes = Int(pieces[pieces.count - 2]) else { return nil }
        let hours = pieces.count == 3 ? (Int(pieces[0]) ?? -1) : 0
        guard hours >= 0 else { return nil }
        return ((hours * 3600 + minutes * 60 + seconds) * 1000) + millis
    }
}

// MARK: - Time formatting (ported from _formatDuration)

private func formatTime(_ ms: Int) -> String {
    let totalSeconds = max(ms, 0) / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

// MARK: - AVPlayer container (UIViewControllerRepresentable wrapping AVPlayerLayer)

private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }
}

private struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerContainerView {
        let v = PlayerContainerView()
        v.backgroundColor = .black
        v.player = player
        return v
    }
    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.player !== player { uiView.player = player }
    }
}

// MARK: - Playback engine (Observable, owns AVPlayer + timers + scrobble)

@MainActor
@Observable
private final class PlaybackEngine {
    let player: AVPlayer
    private let item: MediaItem?
    private let episode: MediaEpisode?
    private let aniSkipEpisode: Int?
    private let startPositionMs: Int?
    private let subtitleUrl: String
    private weak var appState: AppState?

    // Current data source (mutable so we can rebuild the player item on a
    // playback failure, e.g. the One Pace GameDrive proxy's invalid TLS cert).
    private var currentURL: String
    private let headers: [String: String]
    // Guards against repeatedly falling back (parity with Dart `_fallbackAttempted`).
    private var fallbackAttempted = false

    // Observable UI state
    var durationMs: Int = 0
    var positionMs: Int = 0
    var isPlaying = false
    var isReady = false
    var hasError = false
    var errorMessage: String?
    var captionCues: [CaptionCue] = []
    var skipIntervals: [SkipInterval] = []
    var currentCaption: String = ""

    // Fired once when the episode finishes (natural end or AniSkip "ed" skip) so
    // the host PlayerScreen can autoplay the next episode or show recommendations.
    var onEpisodeFinished: (() -> Void)?
    private var episodeFinishedFired = false

    // Scrobble bookkeeping (parity with Dart fields)
    private var activeScrobble = false
    private var finishedScrobble = false
    private var wasPlaying = false
    private var skippedTypes: Set<String> = []

    private var timeObserver: Any?
    private var progressTask: Task<Void, Never>?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    // MARK: Stall watchdog
    // While playing, if the position hasn't advanced for ~12s we re-resolve the
    // stream and resume from the same spot (bounded retries). Checked every ~3s.
    private var stallWatchdogTask: Task<Void, Never>?
    private var lastObservedPositionMs = 0
    private var lastProgressAt = Date()
    private var stallRecoveryCount = 0
    private var isRecoveringStall = false
    private let stallTimeoutSec: TimeInterval = 12
    private let stallCheckIntervalSec: UInt64 = 3
    private let maxStallRecoveries = 3
    // Set true while a user-initiated seek is in flight so the watchdog doesn't
    // mistake the seek settle for a stall.
    private var isSeeking = false
    // True once the user (or auto-start) intends playback — i.e. we called
    // play() and haven't paused. A stuck stream buffers indefinitely with
    // timeControlStatus == .waitingToPlayAtSpecifiedRate and isPlaying == false,
    // which the position-advance check alone never catches; this lets the
    // watchdog recover from that case too.
    private var intendsToPlay = false
    // When the player first entered a "waiting to play" (buffering) state while
    // we intend to play. Reset whenever it leaves that state.
    private var waitingSince: Date?
    // Retained so AVAssetResourceLoader (weak delegate) can accept invalid/
    // self-signed TLS certs on stream hosts (e.g. Pixeldrain/GameDrive proxy).
    private let assetTrust = PermissiveAssetTrust()
    private let assetTrustQueue = DispatchQueue(label: "com.aryaroop.omniverse.assetloader")

    private var isAnime: Bool { item?.type == .anime || item?.isAnime == true }

    init(title: String, url: String, headers: [String: String], item: MediaItem?,
         episode: MediaEpisode?, subtitleUrl: String, startPositionMs: Int?,
         aniSkipEpisode: Int?, appState: AppState?) {
        self.item = item
        self.episode = episode
        self.subtitleUrl = subtitleUrl
        self.startPositionMs = startPositionMs
        self.aniSkipEpisode = aniSkipEpisode
        self.appState = appState
        self.currentURL = url
        self.headers = headers

        let playerItem = Self.makeItem(url: url, headers: headers,
                                       assetTrust: assetTrust, assetTrustQueue: assetTrustQueue)
        self.player = AVPlayer(playerItem: playerItem)
        self.player.automaticallyWaitsToMinimizeStalling = true
    }

    /// Builds an AVPlayerItem for a stream URL + HTTP headers (per contract),
    /// wiring up the permissive TLS trust delegate.
    private static func makeItem(url: String, headers: [String: String],
                                 assetTrust: PermissiveAssetTrust,
                                 assetTrustQueue: DispatchQueue) -> AVPlayerItem {
        let assetURL = URL(string: url) ?? URL(string: "about:blank")!
        let options: [String: Any] = headers.isEmpty
            ? [:]
            : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: assetURL, options: options)
        // Accept invalid/self-signed certs (parity with the app's permissive HTTP).
        asset.resourceLoader.setDelegate(assetTrust, queue: assetTrustQueue)
        return AVPlayerItem(asset: asset)
    }

    func start() {
        // Audio session so playback continues with the silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)

        observeCurrentItem()
        startTimer()
    }

    private var nextEpisodeExists: Bool {
        guard let item, let episode else { return false }
        if item.title == "One Pace" { return true }
        return AutoplayResolver.nextEpisodeFor(item, episode) != nil
    }

    // Periodic time observer (drives scrubber + auto-skip).
    private func startTimer() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Runs on the main queue; hop to the MainActor for isolated access.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.positionMs = Int(time.seconds.isFinite ? time.seconds * 1000 : 0)
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.durationMs = Int(d * 1000)
                }
                self.isPlaying = self.player.timeControlStatus == .playing
                self.updateCaption()
                self.maybeAutoSkip()
                self.handlePlaybackChange()

                // Autoplay next episode when countdown reaches 0 (1s or less remaining)
                if self.nextEpisodeExists, self.durationMs > 0, self.durationMs - self.positionMs <= 1000 {
                    if !self.episodeFinishedFired {
                        self.episodeFinishedFired = true
                        self.onEpisodeFinished?()
                    }
                }
            }
        }

        observeEnd()
    }

    /// Attaches (or re-attaches, after a rebuild) the status KVO on the current
    /// player item. On `.failed` for One Pace it triggers the Pixeldrain fallback.
    private func observeCurrentItem() {
        statusObservation?.invalidate()
        statusObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    if !self.isReady { self.onReady() }
                case .failed:
                    if self.stallRecoveryCount < self.maxStallRecoveries {
                        self.stallRecoveryCount += 1
                        Task { await self.recoverFromStall() }
                    } else if self.tryPixeldrainFallback(error: item.error) {
                        return
                    } else {
                        self.hasError = true
                        self.errorMessage = item.error?.localizedDescription ?? "Could not open this stream."
                    }
                default: break
                }
            }
        }
    }

    private func observeEnd() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleComplete() }
        }
    }

    // MARK: - Pixeldrain fallback (parity with Dart `_handlePlaybackError`)

    /// Returns true if a fallback rebuild was initiated. Applies only to One Pace
    /// (by title) or pixeldrain/gamedrive-hosted URLs, and only once.
    private func tryPixeldrainFallback(error: Error?) -> Bool {
        guard !fallbackAttempted else { return false }
        let host = URL(string: currentURL)?.host?.lowercased() ?? ""
        let isOnePace = item?.title == "One Pace"
            || host.contains("gamedrive")
            || (host.contains("pixeldrain") && currentURL.contains("/api/file/"))
        guard isOnePace else { return false }

        let officialUrl = officialPixeldrainUrl(currentURL)
        // If we're already on the direct pixeldrain.net URL, nothing to fall back to.
        guard officialUrl != currentURL else { return false }

        fallbackAttempted = true
        showToast("Switching to official Pixeldrain server...")
        rebuild(with: officialUrl)
        return true
    }

    /// Builds the direct Pixeldrain URL (`https://pixeldrain.net/api/file/{fileId}`
    /// + optional `?api_key=`) from the current asset URL's last path component.
    private func officialPixeldrainUrl(_ url: String) -> String {
        // Strip any query before extracting the file id (last path component).
        let noQuery = url.components(separatedBy: "?").first ?? url
        guard let comp = noQuery.split(separator: "/").last.map(String.init),
              !comp.isEmpty else { return url }
        var official = "https://pixeldrain.net/api/file/\(comp)"
        let apiKey = appState?.credentials.pixeldrainApiKey.trimmed ?? ""
        if !apiKey.isEmpty { official += "?api_key=\(apiKey)" }
        return official
    }

    /// Swaps in a fresh player item for `newUrl`, preserving the current position,
    /// then re-attaches observers and resumes (parity with `_recreateController`).
    private func rebuild(with newUrl: String, resumeMs: Int? = nil) {
        let resumeAt: CMTime
        if let resumeMs {
            resumeAt = CMTime(value: CMTimeValue(resumeMs), timescale: 1000)
        } else {
            resumeAt = player.currentItem?.currentTime() ?? CMTime(value: CMTimeValue(positionMs), timescale: 1000)
        }
        currentURL = newUrl
        hasError = false
        errorMessage = nil
        let newItem = Self.makeItem(url: newUrl, headers: headers,
                                    assetTrust: assetTrust, assetTrustQueue: assetTrustQueue)
        player.replaceCurrentItem(with: newItem)
        observeCurrentItem()
        observeEnd()
        if resumeAt.isValid && resumeAt.seconds.isFinite && resumeAt.seconds > 0 {
            player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
    }

    private func onReady() {
        isReady = true
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            durationMs = Int(d * 1000)
        }
        if let start = startPositionMs, start > 0 {
            player.seek(to: CMTime(value: CMTimeValue(start), timescale: 1000))
        }
        player.play()
        intendsToPlay = true
        // Progress timer every 10s → recordProgress + scrobble keep-alive.
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self else { return }
                await MainActor.run {
                    self.recordLocalProgress()
                    if let item = self.item, let state = self.appState,
                       self.activeScrobble, !self.finishedScrobble {
                        Task { await state.startTraktPlayback(item, self.progress(), episode: self.episode) }
                    }
                }
            }
        }
        Task { await fetchSkipIntervals() }
        Task { await fetchSubtitles() }
        startStallWatchdog()
    }

    // MARK: - Stall watchdog / auto-recovery

    private func startStallWatchdog() {
        lastObservedPositionMs = positionMs
        lastProgressAt = Date()
        stallWatchdogTask?.cancel()
        stallWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: (self?.stallCheckIntervalSec ?? 3) * 1_000_000_000)
                guard let self else { return }
                await MainActor.run { self.checkForStall() }
            }
        }
    }

    private func checkForStall() {
        // Skip when the user isn't trying to play, or during transient states we
        // shouldn't treat as stalls (seeking, completed, already recovering,
        // errored, not yet ready).
        guard isReady, !hasError, !isRecoveringStall, !isSeeking,
              intendsToPlay, !isComplete() else {
            // Reset baselines so a fresh play/seek doesn't count earlier idle time.
            lastObservedPositionMs = positionMs
            lastProgressAt = Date()
            waitingSince = nil
            return
        }

        let now = Date()

        // Case A — buffering stall: the player is stuck waiting to play at the
        // requested rate (or AVPlayer reports a wait reason) even though we
        // intend to play. isPlaying is false here, so the position-advance check
        // below never fires; track how long we've been waiting and recover.
        let isWaiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            || player.reasonForWaitingToPlay != nil
        if isWaiting {
            if waitingSince == nil { waitingSince = now }
            if let since = waitingSince,
               now.timeIntervalSince(since) >= stallTimeoutSec,
               stallRecoveryCount < maxStallRecoveries {
                stallRecoveryCount += 1
                Task { await recoverFromStall() }
            }
            return
        } else {
            waitingSince = nil
        }

        // Case B — playing but position frozen: only meaningful while actually
        // playing with a known duration.
        guard isPlaying, durationMs > 0 else {
            lastObservedPositionMs = positionMs
            lastProgressAt = now
            return
        }
        if positionMs > lastObservedPositionMs {
            stallRecoveryCount = 0 // Reset since we successfully made progress!
            lastObservedPositionMs = positionMs
            lastProgressAt = now
            return
        }
        // Position hasn't advanced. If it's been stalled past the threshold and
        // we still have retries left, re-resolve and resume.
        if now.timeIntervalSince(lastProgressAt) >= stallTimeoutSec,
           stallRecoveryCount < maxStallRecoveries {
            stallRecoveryCount += 1
            Task { await recoverFromStall() }
        }
    }

    /// Re-resolves the current stream and rebuilds the player item at the saved
    /// position. One Pace rebuilds via the existing Pixeldrain URL path; other
    /// direct sources re-fetch via `playbackSourcesFor` and take the first
    /// direct source.
    private func recoverFromStall() async {
        guard !isRecoveringStall else { return }
        isRecoveringStall = true
        defer { isRecoveringStall = false }
        showToast("Reconnecting…")

        let resumeMs = positionMs
        let host = URL(string: currentURL)?.host?.lowercased() ?? ""
        let isOnePace = item?.title == "One Pace"
            || host.contains("gamedrive")
            || (host.contains("pixeldrain") && currentURL.contains("/api/file/"))

        if isOnePace {
            // Re-resolve using the bypass proxy instead of immediately falling back to official!
            // This is what the userscript does and keeps the stream working.
            let noQuery = currentURL.components(separatedBy: "?").first ?? currentURL
            let fileId = noQuery.split(separator: "/").last.map(String.init) ?? ""
            if !fileId.isEmpty {
                let apiKey = appState?.credentials.pixeldrainApiKey.trimmed ?? ""
                let bypassUrl = await OnePaceResolver.streamUrl(fileId: fileId, apiKey: apiKey)
                rebuild(with: bypassUrl, resumeMs: resumeMs)
            } else {
                rebuild(with: officialPixeldrainUrl(currentURL), resumeMs: resumeMs)
            }
            resetStallBaseline(resumeMs)
            return
        }

        // Anime / direct sources: re-fetch and take the first direct source.
        guard let item, let state = appState else {
            rebuild(with: currentURL, resumeMs: resumeMs)
            resetStallBaseline(resumeMs)
            return
        }
        do {
            let sources = try await state.playbackSourcesFor(item, episode: episode)
            if let direct = sources.first(where: { $0.isDirect }) {
                rebuild(with: direct.url, resumeMs: resumeMs)
            } else {
                rebuild(with: currentURL, resumeMs: resumeMs)
            }
        } catch {
            rebuild(with: currentURL, resumeMs: resumeMs)
        }
        resetStallBaseline(resumeMs)
    }

    /// Resets the watchdog baselines after a recovery rebuild so the freshly
    /// rebuilt stream gets a clean window before being considered stalled again.
    private func resetStallBaseline(_ resumeMs: Int) {
        lastProgressAt = Date()
        lastObservedPositionMs = resumeMs
        waitingSince = nil
        intendsToPlay = true
    }

    // MARK: scrobble lifecycle (ported from _handlePlaybackChange)

    private func handlePlaybackChange() {
        guard let item, let state = appState, isReady else { return }
        let playing = isPlaying
        if playing && !activeScrobble {
            activeScrobble = true
            finishedScrobble = false
            wasPlaying = true
            Task { await state.startTraktPlayback(item, progress(), episode: episode) }
        } else if !playing && wasPlaying && !isComplete() {
            wasPlaying = false
            activeScrobble = false
            Task { await state.pauseTraktPlayback(item, progress(), episode: episode) }
        }
        if !finishedScrobble && isComplete() {
            finishedScrobble = true
            activeScrobble = false
            Task { await state.stopTraktPlayback(item, 100, episode: episode) }
        }
    }

    private func handleComplete() {
        if let item, let state = appState, !finishedScrobble {
            finishedScrobble = true
            activeScrobble = false
            Task { await state.stopTraktPlayback(item, 100, episode: episode) }
        }
        fireEpisodeFinished()
    }

    /// Notifies the host exactly once that the episode is over.
    private func fireEpisodeFinished() {
        guard !episodeFinishedFired else { return }
        episodeFinishedFired = true
        onEpisodeFinished?()
    }

    func play() { player.play(); isPlaying = true; intendsToPlay = true; waitingSince = nil }
    func pause() { player.pause(); isPlaying = false; intendsToPlay = false; waitingSince = nil }

    func seekBy(_ seconds: Double) {
        guard durationMs > 0 else { return }
        let next = Double(positionMs) / 1000.0 + seconds
        let bounded = min(max(next, 0), Double(durationMs) / 1000.0)
        seekGuarded(to: CMTime(seconds: bounded, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekTo(fraction: Double) {
        guard durationMs > 0 else { return }
        let target = Double(durationMs) / 1000.0 * min(max(fraction, 0), 1)
        seekGuarded(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    func seekToBeginning() {
        seekGuarded(to: .zero)
    }

    /// Seeks while marking `isSeeking` so the stall watchdog ignores the
    /// transient pause/buffer the seek causes, then resets its baseline.
    private func seekGuarded(to time: CMTime,
                             toleranceBefore: CMTime = .positiveInfinity,
                             toleranceAfter: CMTime = .positiveInfinity) {
        isSeeking = true
        player.seek(to: time, toleranceBefore: toleranceBefore, toleranceAfter: toleranceAfter) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSeeking = false
                self.lastObservedPositionMs = self.positionMs
                self.lastProgressAt = Date()
            }
        }
    }

    private func progress() -> Double {
        guard durationMs > 0 else { return 0 }
        return Double(positionMs) / Double(durationMs) * 100
    }

    private func isComplete() -> Bool {
        guard durationMs > 0 else { return false }
        return positionMs >= durationMs - 2000 || positionMs >= durationMs
    }

    private func recordLocalProgress() {
        guard let item, let state = appState, durationMs > 0 else { return }
        Task { await state.recordProgress(item: item, positionMs: positionMs, durationMs: durationMs, episode: episode) }
    }

    // MARK: AniSkip (ported from _fetchSkipIntervals / _maybeAutoSkip)

    private func fetchSkipIntervals() async {
        guard item?.title != "One Pace" else { return }
        guard let item, let episode, let anilistId = item.anilistId else { return }
        let lengthSec = durationMs / 1000
        guard lengthSec > 0 else { return }
        let intervals = await AniSkipApi.fetch(anilistId: anilistId,
                                               episode: aniSkipEpisode ?? episode.episodeNumber,
                                               episodeLengthSec: lengthSec)
        if !intervals.isEmpty { skipIntervals = intervals }
    }

    var toastMessage: String?
    private var toastTask: Task<Void, Never>?
    func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { self?.toastMessage = nil }
        }
    }

    private func maybeAutoSkip() {
        guard !skipIntervals.isEmpty, isPlaying else { return }
        for interval in skipIntervals {
            if skippedTypes.contains(interval.type) { continue }
            if positionMs >= interval.startMs && positionMs < interval.endMs - 1000 {
                skippedTypes.insert(interval.type)
                if interval.type == "ed" {
                    showToast("Skipped Ending")
                    finishedScrobble = true
                    activeScrobble = false
                    if let state = appState, let item {
                        Task { await state.stopTraktPlayback(item, 100, episode: episode) }
                    }
                    fireEpisodeFinished()
                } else {
                    player.seek(to: CMTime(value: CMTimeValue(interval.endMs), timescale: 1000))
                    let label: String
                    switch interval.type {
                    case "op": label = "Skipped Intro"
                    case "recap": label = "Skipped Recap"
                    default: label = "Skipped"
                    }
                    showToast(label)
                }
                break
            }
        }
    }

    /// Manual Skip Intro: +85s (parity with Dart `onSeekBy(85s)`).
    func skipIntro() { seekBy(85) }

    var showManualSkipIntro: Bool { isAnime && skipIntervals.isEmpty }

    // MARK: Captions

    private func fetchSubtitles() async {
        let trimmed = subtitleUrl.trimmed
        guard let uri = URL(string: trimmed),
              uri.scheme == "http" || uri.scheme == "https" else { return }
        do {
            let r = try await Http.shared.request(uri, timeout: 12)
            guard r.status < 400 else { return }
            let cues = CaptionParser.parse(r.bodyString)
            captionCues = cues
        } catch { /* leave captions empty */ }
    }

    private func updateCaption() {
        guard !captionCues.isEmpty else {
            if !currentCaption.isEmpty { currentCaption = "" }
            return
        }
        let cue = captionCues.first { positionMs >= $0.startMs && positionMs <= $0.endMs }
        let text = cue?.text ?? ""
        if text != currentCaption { currentCaption = text }
    }

    // MARK: teardown

    func tearDown() {
        // Pause scrobble if still active and not finished (parity with dispose()).
        if let item, let state = appState, activeScrobble, !finishedScrobble {
            Task { await state.pauseTraktPlayback(item, progress(), episode: episode) }
        }
        recordLocalProgress()
        progressTask?.cancel()
        stallWatchdogTask?.cancel()
        toastTask?.cancel()
        statusObservation?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - PlayerScreen (public)

struct PlayerScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // The currently-playing route. Swapped in place by autoplay so the same
    // PlayerScreen rolls straight into the next episode without a new push.
    @State private var route: PlayerRoute

    @State private var engine: PlaybackEngine?
    @State private var controlsVisible = true
    @State private var controlsHideTask: Task<Void, Never>?
    @State private var userPaused = false
    @State private var showCaptions = true
    @State private var selectedAudio = "Original Stereo"
    @State private var showAudioSheet = false
    @State private var showSubtitlesSheet = false
    @State private var dragOffset: CGFloat = 0

    // End-of-show recommendations. Non-nil once the show is over with nothing
    // left to autoplay; drives the recommendation overlay.
    @State private var recommendations: [MediaItem]? = nil
    @State private var loadingRecommendations = false
    @State private var recommendationDetail: MediaItem? = nil   // tapped recommendation
    @State private var nextVidsrc: VidsrcRoute? = nil           // next episode is a VidSrc embed

    init(title: String, url: String, headers: [String: String] = [:],
         item: MediaItem? = nil, episode: MediaEpisode? = nil,
         subtitleUrl: String = "", startPositionMs: Int? = nil,
         aniSkipEpisode: Int? = nil) {
        _route = State(initialValue: PlayerRoute(
            title: title, url: url, headers: headers, item: item, episode: episode,
            subtitleUrl: subtitleUrl, startPositionMs: startPositionMs, aniSkipEpisode: aniSkipEpisode))
    }

    private var title: String { route.title }
    private var item: MediaItem? { route.item }
    private var episode: MediaEpisode? { route.episode }
    private var isAnime: Bool { item?.type == .anime || item?.isAnime == true }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Backdrop dims as the user drags to dismiss.
                let dragFraction = Double(min(max(dragOffset / (geo.size.height * 0.22), 0), 1))
                Color.black.opacity(1.0 - dragFraction * 0.7).ignoresSafeArea()

                content(geo: geo)
                    .offset(y: dragOffset)

                if recommendations != nil || loadingRecommendations {
                    recommendationsOverlay(geo: geo)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .keepScreenAwake(true)
        .gesture(dragToDismiss)
        // Rebuilds the engine whenever the route changes (autoplay swap), tearing
        // down the previous one first.
        .task(id: route.id) {
            engine?.tearDown()
            recommendations = nil
            loadingRecommendations = false
            let e = PlaybackEngine(title: route.title, url: route.url, headers: route.headers,
                                   item: route.item, episode: route.episode, subtitleUrl: route.subtitleUrl,
                                   startPositionMs: route.startPositionMs,
                                   aniSkipEpisode: route.aniSkipEpisode, appState: appState)
            e.onEpisodeFinished = { handleEpisodeFinished() }
            engine = e
            e.start()
            // Initial audio label parity with didChangeDependencies.
            selectedAudio = isAnime
                ? (appState.settings.preferDubbedAnime ? "English (Dubbed)" : "Japanese (Subbed)")
                : "Original Stereo"
            scheduleControlsHide()
        }
        .onAppear {
            PlayerOrientation.forceLandscape()
            DeviceTuning.keepScreenOn(true)
        }
        .onDisappear {
            PlayerOrientation.restore()
            DeviceTuning.keepScreenOn(false)
            engine?.tearDown()
            if appState.credentials.hasTraktUser {
                Task { try? await appState.syncSettingsToTrakt(silent: true) }
            }
        }
        // A recommended title opens its own detail screen on top of the player.
        .fullScreenCover(item: $recommendationDetail) { rec in
            MediaDetailScreen(item: rec)
        }
        // The next episode resolved to a VidSrc embed — present the resolver.
        .fullScreenCover(item: $nextVidsrc) { v in
            VidsrcResolveScreen(item: v.item, title: v.title, embedUrls: v.embedUrls, episode: v.episode)
        }
    }

    /// Called once when the current episode finishes. Tries to autoplay the next
    /// episode; if there is nothing left, loads recommendations for the end screen.
    private func handleEpisodeFinished() {
        guard recommendations == nil, !loadingRecommendations else { return }
        Task {
            if let next = await AutoplayResolver.resolveNext(item: route.item, episode: route.episode, appState: appState) {
                switch next {
                case .player(let r):
                    engine?.showToast("Playing \(nextLabel(r))")
                    route = r
                case .vidsrc(let v):
                    nextVidsrc = v
                }
                return
            }
            loadingRecommendations = true
            let recs = await appState.recommendationsFor(route.item)
            loadingRecommendations = false
            if recs.isEmpty { dismiss() } else { recommendations = recs }
        }
    }

    private func nextLabel(_ r: PlayerRoute) -> String {
        if let ep = r.episode { return "Episode \(ep.episodeNumber)" }
        return r.title
    }

    // MARK: - End-of-show recommendations

    @ViewBuilder
    private func recommendationsOverlay(geo: GeometryProxy) -> some View {
        let showTitle = (route.item?.title ?? title).split(separator: "•").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? title
        RecommendationsEndOverlay(
            showTitle: showTitle,
            recommendations: recommendations,
            loading: loadingRecommendations,
            onSelect: { recommendationDetail = $0 },
            onClose: { dismiss() })
    }

    @ViewBuilder
    private func content(geo: GeometryProxy) -> some View {
        if let engine {
            ZStack {
                if engine.hasError {
                    PlayerErrorView(message: engine.errorMessage ?? "Could not open this stream.") { dismiss() }
                } else if !engine.isReady {
                    PlayerLoadingView(title: title, message: "Opening stream...") { dismiss() }
                } else {
                    stage(engine: engine, geo: geo)
                }

                if let toast = engine.toastMessage {
                    VStack {
                        GlassPanel(cornerRadius: 999, opacity: 0.22, borderOpacity: 0.28, padding: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "forward.end.fill")
                                    .foregroundStyle(LiquidColors.cyan)
                                Text(toast).font(.system(size: 16, weight: .black))
                                    .foregroundStyle(.white)
                            }
                        }
                        .fixedSize()
                    }
                    .allowsHitTesting(false)
                }
            }
        } else {
            PlayerLoadingView(title: title, message: "Opening stream...") { dismiss() }
        }
    }

    @ViewBuilder
    private func stage(engine: PlaybackEngine, geo: GeometryProxy) -> some View {
        ZStack {
            VideoSurface(player: engine.player)
                .ignoresSafeArea()

            // Tap to toggle controls.
            Color.clear.contentShape(Rectangle())
                .onTapGesture { showControls() }

            // Captions overlay
            if showCaptions && !engine.currentCaption.isEmpty {
                VStack {
                    Spacer()
                    Text(engine.currentCaption)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.black.opacity(0.58))
                        .padding(.horizontal, 48)
                        .padding(.bottom, controlsVisible ? 150 : 42)
                }
                .allowsHitTesting(false)
            }

            if userPaused {
                pauseInfoOverlay(engine: engine)
            } else {
                playingControls(engine: engine)
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                    .animation(.easeOut(duration: 0.24), value: controlsVisible)
            }

            // Manual Skip Intro (anime without AniSkip data).
            if engine.showManualSkipIntro {
                skipIntroButton(engine: engine)
            }

            nextEpisodeOverlay(engine: engine)
        }
    }

    private var nextEpisode: MediaEpisode? {
        guard let item = route.item, let ep = route.episode else { return nil }
        return AutoplayResolver.nextEpisodeFor(item, ep)
    }

    @ViewBuilder
    private func nextEpisodeOverlay(engine: PlaybackEngine) -> some View {
        let remainingSecs = max(0, (engine.durationMs - engine.positionMs) / 1000)
        let isLast10Sec = engine.durationMs > 0 && (engine.durationMs - engine.positionMs <= 10000)

        if isLast10Sec, let nextEp = nextEpisode {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        handleEpisodeFinished()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(12)
                                .background(Color.white, in: Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Next Episode Playing in \(remainingSecs)s")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(LiquidColors.cyan)
                                Text("S\(nextEp.seasonNumber) • E\(nextEp.episodeNumber): \(nextEp.title)")
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }

                            ZStack {
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                                    .frame(width: 36, height: 36)
                                Circle()
                                    .trim(from: 0, to: CGFloat(remainingSecs) / 10.0)
                                    .stroke(LiquidColors.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 36, height: 36)
                                    .animation(.linear(duration: 0.25), value: remainingSecs)
                                Text("\(remainingSecs)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .background(Color.black.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.4), radius: 10, y: 5)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28)
                    .padding(.bottom, controlsVisible ? 120 : 36)
                }
            }
        }
    }

    // MARK: - Playing controls overlay

    @ViewBuilder
    private func playingControls(engine: PlaybackEngine) -> some View {
        ZStack {
            // Vignette
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.66), location: 0),
                    .init(color: .clear, location: 0.23),
                    .init(color: .clear, location: 0.60),
                    .init(color: Color.black.opacity(0.80), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack {
                topControls
                Spacer()
                centerControls(engine: engine)
                Spacer()
                bottomControls(engine: engine)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var topControls: some View {
        HStack(spacing: 12) {
            circleButton("xmark") { dismiss() }
            circleButton("arrow.up.left.and.arrow.down.right") { showControls() }
            Spacer()
            circleButton("speaker.wave.2.fill") { showControls() }
        }
    }

    @ViewBuilder
    private func centerControls(engine: PlaybackEngine) -> some View {
        HStack(spacing: 74) {
            largeButton("gobackward.10", size: 82) {
                showControls(); engine.seekBy(-10)
            }
            largeButton(engine.isPlaying ? "pause.fill" : "play.fill", size: 112) {
                showControls()
                if engine.isPlaying { engine.pause(); userPaused = true }
                else { engine.play(); userPaused = false }
            }
            largeButton("goforward.10", size: 82) {
                showControls(); engine.seekBy(10)
            }
        }
    }

    @ViewBuilder
    private func bottomControls(engine: PlaybackEngine) -> some View {
        let isLive = engine.durationMs <= 0
        let remaining = isLive ? "" : "-" + formatTime(engine.durationMs - engine.positionMs)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(isLive ? "LIVE" : formatTime(engine.positionMs))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                Scrubber(
                    fraction: engine.durationMs > 0 ? Double(engine.positionMs) / Double(engine.durationMs) : 0,
                    isLive: isLive,
                    onScrub: { f in showControls(); engine.seekTo(fraction: f) }
                )
                .frame(height: 28)
                Text(remaining)
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.7))
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(displayTitle)
                        .font(.system(size: 20, weight: .black)).foregroundStyle(.white)
                        .lineLimit(1)
                    if !isLive {
                        HStack(spacing: 8) {
                            pill("Info", background: .white, foreground: .black)
                            pill("Continue Watching", background: .white.opacity(0.12), foreground: .white)
                        }
                    }
                }
                Spacer()
                if !isLive {
                    smallIcon("waveform") { showControls(); showAudioSheet = true }
                    smallIcon("text.bubble") { showControls(); showSubtitlesSheet = true }
                }
            }
        }
        .sheet(isPresented: $showAudioSheet) {
            AudioSheet(current: selectedAudio, isAnime: isAnime) { sel in
                selectedAudio = sel
            }
            .presentationDetents([.height(220)])
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showSubtitlesSheet) {
            SubtitlesSheet(showCaptions: showCaptions) { on in showCaptions = on }
                .presentationDetents([.height(220)])
                .presentationBackground(.clear)
        }
    }

    // MARK: - Pause / info overlay

    @ViewBuilder
    private func pauseInfoOverlay(engine: PlaybackEngine) -> some View {
        let isLive = engine.durationMs <= 0
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
                .onTapGesture { engine.play(); userPaused = false }
            VStack {
                HStack(spacing: 12) {
                    circleButton("xmark") { dismiss() }
                    if !isLive { circleButton("arrow.up.left.and.arrow.down.right") { showControls() } }
                    Spacer()
                    circleButton("speaker.wave.2.fill") { showControls() }
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 48) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !isLive {
                            HStack(spacing: 8) {
                                pill("Info", background: .white, foreground: .black)
                                pill("Continue Watching", background: .white.opacity(0.12), foreground: .white)
                            }
                        }
                        Text(displayTitle).font(.system(size: 28, weight: .black)).foregroundStyle(.white)
                        if !isLive {
                            Text(overviewText).font(.system(size: 14)).foregroundStyle(.white.opacity(0.82))
                                .lineLimit(3)
                            Text(metaText).font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    if !isLive {
                        VStack(spacing: 12) {
                            overlayActionButton("play.fill", "Resume Playback") { engine.play(); userPaused = false }
                            overlayActionButton("play", "From Beginning") { engine.seekToBeginning(); engine.play(); userPaused = false }
                            overlayActionButton("info", "More Info") { dismiss() }
                        }
                        .frame(maxWidth: 280)
                    }
                }
                .padding(.horizontal, 48).padding(.bottom, 48)
            }
        }
    }

    // MARK: - Skip intro button

    @ViewBuilder
    private func skipIntroButton(engine: PlaybackEngine) -> some View {
        let posSec = engine.positionMs / 1000
        let visible = posSec >= 5 && posSec <= 120
        if visible {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { engine.skipIntro() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "forward.end.fill").font(.system(size: 16))
                            Text("Skip Intro").font(.system(size: 15, weight: .heavy))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Color.black.opacity(0.66), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 28).padding(.bottom, 110)
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Small reusable views

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func largeButton(_ icon: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.11), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func smallIcon(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func pill(_ text: String, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold)).foregroundStyle(foreground)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func overlayActionButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.white)
                Text(label).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
            }
            .frame(height: 54)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 27))
            .overlay(RoundedRectangle(cornerRadius: 27).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Title / meta derivation (ported from _BottomPlayerControls / _PauseInfoOverlay)

    private var displayTitle: String {
        var t = title
        if t.hasPrefix("One Pace • ") {
            t = String(t.dropFirst("One Pace • ".count))
            return t
        }
        if let episode {
            let parts = title.split(separator: "•" as Character, omittingEmptySubsequences: false)
            let cleanShowTitle = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? title
            if cleanShowTitle.lowercased() == "one pace" { return title }
            let epNum = "S\(episode.seasonNumber)E\(episode.episodeNumber)"
            let epTitle = (!episode.title.trimmed.isEmpty && !episode.title.lowercased().hasPrefix("episode"))
                ? episode.title : "Episode \(episode.episodeNumber)"
            return "\(cleanShowTitle) • \(epNum) • \(epTitle)"
        }
        return t
    }

    private var metaText: String {
        guard let item else { return "Movie • Streaming" }
        return "\(item.type.label) • \(item.genres.prefix(2).joined(separator: " • "))"
    }

    private var overviewText: String {
        guard let item, !item.overview.isEmpty else {
            return "Discover details, sources, and watchlist actions in one place."
        }
        return item.overview
    }

    // MARK: - Controls auto-hide

    private func showControls() {
        controlsHideTask?.cancel()
        if !controlsVisible { controlsVisible = true }
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { controlsVisible = false }
        }
    }

    // MARK: - Drag to dismiss (offset>0.22*height or velocity>900)

    private var dragToDismiss: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                let height = UIScreen.main.bounds.height
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let shouldDismiss = velocity > 900 || dragOffset > height * 0.22
                if shouldDismiss {
                    engine?.pause()
                    dismiss()
                } else {
                    withAnimation(.easeOut(duration: 0.22)) { dragOffset = 0 }
                }
            }
    }
}

// MARK: - Scrubber

private struct Scrubber: View {
    let fraction: Double
    let isLive: Bool
    let onScrub: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 4)
                if !isLive {
                    Capsule().fill(Color.white)
                        .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)), height: 4)
                } else {
                    Capsule().fill(Color.white).frame(height: 4)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard !isLive, geo.size.width > 0 else { return }
                        onScrub(Double(v.location.x / geo.size.width))
                    }
            )
        }
    }
}

// MARK: - Bottom sheets (Audio / Subtitles — ported from _showAudioSheet/_showSubtitlesSheet)

private struct AudioSheet: View {
    let current: String
    let isAnime: Bool
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        sheetContainer(title: "Audio") {
            if isAnime {
                optionTile("Japanese (Subbed)", selected: current == "Japanese (Subbed)") { pick("Japanese (Subbed)") }
                optionTile("English (Dubbed)", selected: current == "English (Dubbed)") { pick("English (Dubbed)") }
            } else {
                optionTile("Original Stereo", selected: true) { pick("Original Stereo") }
            }
        }
    }

    private func pick(_ v: String) { onSelect(v); dismiss() }
}

private struct SubtitlesSheet: View {
    let showCaptions: Bool
    let onSelect: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        sheetContainer(title: "Subtitles") {
            optionTile("On", selected: showCaptions) { onSelect(true); dismiss() }
            optionTile("Off", selected: !showCaptions) { onSelect(false); dismiss() }
        }
    }
}

@ViewBuilder
private func sheetContainer<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        Capsule().fill(Color.white.opacity(0.24)).frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
        Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity)
        content()
        Spacer(minLength: 0)
    }
    .padding(.horizontal, 24).padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(Color(.sRGB, white: 0.10, opacity: 0.92))
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
}

@ViewBuilder
private func optionTile(_ title: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
    Button(action: onTap) {
        HStack {
            Image(systemName: selected ? "checkmark" : "")
                .font(.system(size: 18)).foregroundStyle(.blue).frame(width: 20)
            Text(title).font(.system(size: 14, weight: selected ? .bold : .regular)).foregroundStyle(.white)
            Spacer()
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
    }
    .buttonStyle(.plain)
}

// MARK: - Loading / error views (ported from _PlayerLoading / _PlayerError)

struct PlayerLoadingView: View {
    let title: String
    let message: String
    var onClose: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let onClose {
                VStack { HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.ultraThinMaterial, in: Circle())
                    }.buttonStyle(.plain)
                    Spacer()
                }.padding(16); Spacer() }
            }
            VStack(spacing: 16) {
                ProgressView().scaleEffect(1.4).tint(LiquidColors.cyan)
                Text(title).font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).lineLimit(2)
                Text(message).font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(0.72))
            }
            .padding(28)
        }
    }
}

struct PlayerErrorView: View {
    let message: String
    var onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 42)).foregroundStyle(.white)
                Text(message).font(.system(size: 16, weight: .bold)).foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                Button(action: onClose) {
                    Label("Close", systemImage: "xmark")
                }.buttonStyle(AccentButtonStyle()).fixedSize()
            }
            .padding(28)
        }
    }
}
