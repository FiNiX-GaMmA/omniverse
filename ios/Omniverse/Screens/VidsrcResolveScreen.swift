import SwiftUI
import WebKit
import UIKit

/// Plays a VidSrc title inside a WKWebView, mirroring `truelockmc/streambert`:
///   1. Load `vidsrc-embed.ru/embed/...`.
///   2. Regex-extract the cloudnestra iframe URL (`/rcp/<hash>`) + data-hash list.
///   3. Navigate the same WebView (top-level) to that cloudnestra URL.
///   4. Regex-extract the `src: '/prorcp/…'` path from the rcp page.
///   5. The /prorcp page is the player and auto-plays.
///
/// JS guards are injected on every navigation. We deliberately do NOT spoof a
/// desktop UA here — cloudnestra gates /rcp/<hash> behind Cloudflare Turnstile,
/// which fingerprints WebViews; the platform's real WebView UA clears it.

private enum VidsrcStage { case embed, player, done }

private struct VidsrcServer: Equatable {
    let name: String
    let hash: String
}

private struct EmbedProbe {
    let title: String
    let iframeSrc: String
    let servers: [VidsrcServer]
    let hasChallenge: Bool
    let diagnostic: String
}

private struct PlayerProbe {
    let hasPlayButton: Bool
    let iframeLoaded: Bool
    let hasChallenge: Bool
    let hasTurnstile: Bool
    let hasRcpToken: Bool
    let diagnostic: String
}

// MARK: - Sandbox defeat (runs at documentStart in ALL frames)
//
// The cloudnestra player nests its <iframe> with a `sandbox` attribute, which
// blocks playback ("sandbox not allowed — remove sandbox from iframe to play").
// We (a) make Element.setAttribute IGNORE any `sandbox` attempt and neuter the
// HTMLIFrameElement.sandbox setter, and (b) actively strip+reload any sandboxed
// iframe so it reloads UNsandboxed. Runs immediately, on a 500ms interval, and
// from a MutationObserver.

private let unsandboxJS = #"""
(function () {
  if (window.__omniplayUnsandbox) return;
  window.__omniplayUnsandbox = true;

  try {
    var origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      try { if (name && String(name).toLowerCase() === 'sandbox') return; } catch (_) {}
      return origSetAttribute.apply(this, arguments);
    };
  } catch (_) {}

  try {
    var sandboxDesc = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'sandbox');
    if (sandboxDesc && sandboxDesc.set) {
      Object.defineProperty(HTMLIFrameElement.prototype, 'sandbox', {
        configurable: true, enumerable: true,
        get: function () { try { return sandboxDesc.get.call(this); } catch (_) { return null; } },
        set: function () { /* ignore */ }
      });
    }
  } catch (_) {}

  var unsandbox = function () {
    try {
      var frames = document.querySelectorAll('iframe[sandbox]');
      for (var i = 0; i < frames.length; i++) {
        var f = frames[i];
        if (f.getAttribute('data-omniplay-unsandboxed') === '1') {
          if (f.hasAttribute('sandbox')) { try { f.removeAttribute('sandbox'); } catch (_) {} }
          continue;
        }
        f.setAttribute('data-omniplay-unsandboxed', '1');
        try { f.removeAttribute('sandbox'); } catch (_) {}
        try {
          var src = f.getAttribute('src');
          if (src) { f.setAttribute('src', 'about:blank'); f.setAttribute('src', src); }
        } catch (_) {}
      }
    } catch (_) {}
  };

  unsandbox();
  try { setInterval(unsandbox, 500); } catch (_) {}
  try {
    new MutationObserver(unsandbox).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['sandbox'] });
  } catch (_) {}
})();
"""#

// MARK: - Heavy ad guards + Overlay Killer JS (ported 1:1 from _injectGuards)

private let vidsrcGuardJS = #"""
(function () {
  if (window.__omniplayGuards) return;
  window.__omniplayGuards = true;

  try {
    const style = document.createElement('style');
    style.type = 'text/css';
    style.innerHTML = '* { -webkit-tap-highlight-color: transparent !important; -webkit-tap-highlight-color: rgba(0,0,0,0) !important; outline: none !important; }';
    document.documentElement.appendChild(style);
  } catch (_) {}

  try { window.open = function () { return null; }; } catch (_) {}
  const noop = function () {};
  try { window.alert = noop; window.confirm = function () { return false; }; window.prompt = function () { return null; }; } catch (_) {}

  try {
    const origAddEventListener = window.addEventListener;
    window.addEventListener = function (type, listener, options) {
      if (type === 'beforeunload' || type === 'unload') { return; }
      origAddEventListener.apply(this, arguments);
    };
  } catch (_) {}

  const safeHosts = [
    'vidsrc', 'cloudnestra', 'vsembed', 'vsrc.', 'vidsrcme', 'about:',
    'localhost', '127.0.0.1', 'cdn', '2embed', 'embed.su', 'autoembed',
    'multiembed', 'rabbitstream', 'megacloud', 'streamtape', 'streamlare',
    'doodstream', 'mixdrop', 'vidplay', 'filemoon', 'upstream', 'fembed',
    'streamhide', 'mp4upload', 'streamsb', 'voe.sx', 'streamwish',
    'vidcloud', 'youtube'
  ];

  const isAdHost = function (url) {
    try {
      if (!url) return false;
      const host = new URL(url, location.href).hostname.toLowerCase();
      return !safeHosts.some(function (h) { return host.indexOf(h) >= 0; });
    } catch (_) { return false; }
  };

  const adTokens = [
    'ads', 'ad-', 'analytics', 'doubleclick', 'googletagmanager',
    'googletagservices', 'pagead', 'popunder', 'popcash', 'propellerads',
    'adservice', 'adsco', 'rtmark', 'taloseempest', 'profitable',
    'preferencenail', 'protrafficinspector', 'histats', 'weirdopt',
    'usrpubtrk', 'adexchangeclear', 'realizationnewestfangs',
    'unbrownunflat', 'sixmossin', 'malocacomals', 'cloudflareinsights',
    'kettledroopingcontinuation', 'wayfarerorthodox', 'woxaglasuy',
    'adeptspiritual', 'calculating-laugh', 'amavhxdlofklxjg',
    'videasy', 'bvtpk', 'b7510', 'adx1', 'intelligenceadx', 'yandex',
    'tmstr4', 'tmstr.', 'nectsideaments', 'wbamedia', 'click', 'track', 'redirect', 'pop'
  ];

  const isAdSrc = function (src) {
    if (!src) return false;
    const s = String(src).toLowerCase();
    const isSafe = safeHosts.some(function (h) { return s.indexOf(h) >= 0; });
    if (isSafe) return false;
    return adTokens.some(function (t) { return s.indexOf(t) >= 0; });
  };

  try {
    const origAssign = window.location.assign.bind(window.location);
    const origReplace = window.location.replace.bind(window.location);
    window.location.assign = function (u) { if (!isAdHost(u)) origAssign(u); };
    window.location.replace = function (u) { if (!isAdHost(u)) origReplace(u); };
    const descHref = Object.getOwnPropertyDescriptor(Location.prototype, 'href');
    if (descHref && descHref.set) {
      Object.defineProperty(Location.prototype, 'href', {
        configurable: true, enumerable: true,
        get() { return descHref.get.call(this); },
        set(v) { if (!isAdHost(v)) descHref.set.call(this, v); }
      });
    }
  } catch (_) {}

  try {
    const origWrite = document.write.bind(document);
    document.write = function (html) { if (isAdSrc(html)) { return; } origWrite(html); };
    const origWriteln = document.writeln.bind(document);
    document.writeln = function (html) { if (isAdSrc(html)) { return; } origWriteln(html); };
  } catch (_) {}

  const fixAnchors = function () {
    document.querySelectorAll('a[target]').forEach(function (a) {
      const t = a.getAttribute('target');
      if (t === '_blank' || t === '_top' || t === '_parent') a.removeAttribute('target');
    });
  };

  const stripAds = function () {
    document.querySelectorAll('iframe').forEach(function (f) { if (isAdSrc(f.src)) f.remove(); });
    document.querySelectorAll('script').forEach(function (s) { if (isAdSrc(s.src)) s.remove(); });
    fixAnchors();
  };
  stripAds();

  try {
    const descScript = Object.getOwnPropertyDescriptor(HTMLScriptElement.prototype, 'src');
    if (descScript && descScript.set) {
      Object.defineProperty(HTMLScriptElement.prototype, 'src', {
        configurable: true, enumerable: true,
        get() { return descScript.get.call(this); },
        set(v) { if (!isAdSrc(v)) descScript.set.call(this, v); }
      });
    }
    const descIframe = Object.getOwnPropertyDescriptor(HTMLIFrameElement.prototype, 'src');
    if (descIframe && descIframe.set) {
      Object.defineProperty(HTMLIFrameElement.prototype, 'src', {
        configurable: true, enumerable: true,
        get() { return descIframe.get.call(this); },
        set(v) { if (!isAdSrc(v)) descIframe.set.call(this, v); }
      });
    }
  } catch (_) {}

  try {
    new MutationObserver(stripAds).observe(document.documentElement, {
      childList: true, subtree: true
    });
  } catch (_) {}

  document.addEventListener('click', function (e) {
    const a = e.target && e.target.closest && e.target.closest('a[href]');
    if (a && isAdHost(a.href)) { e.preventDefault(); e.stopPropagation(); }
  }, true);

  // Overlay Killer.
  setInterval(function () {
    const divs = document.querySelectorAll('div');
    const sw = window.innerWidth;
    const sh = window.innerHeight;
    for (var i = 0; i < divs.length; i++) {
      const div = divs[i];
      const style = window.getComputedStyle(div);
      if (style.position === 'absolute' || style.position === 'fixed') {
        const z = parseInt(style.zIndex, 10);
        if (z > 99) {
          const w = div.offsetWidth;
          const h = div.offsetHeight;
          if (w > sw * 0.5 && h > sh * 0.5) {
            if (!div.querySelector('video, iframe, canvas, img') && div.innerText.trim().length < 50) {
              div.remove();
            }
          }
        }
      }
    }
  }, 500);
})();
"""#

private let embedProbeJS = #"""
(function () {
  try {
    var html = document.documentElement.outerHTML || '';
    var iframeMatch = html.match(/<iframe[^>]+src=["']([^"']+)["']/i);
    var iframeSrc = iframeMatch ? iframeMatch[1] : '';
    var nameRe = /data-hash=["']([^"']+)["'][^>]*>([\s\S]*?)<\/div>/g;
    var simpleRe = /data-hash=["']([^"']+)["']/g;
    var seen = {};
    var servers = [];
    var m;
    while ((m = nameRe.exec(html)) !== null) {
      var hash = m[1];
      if (!hash || seen[hash]) continue;
      seen[hash] = true;
      var name = (m[2] || '').replace(/<[^>]*>/g, '').trim();
      servers.push({ name: name, hash: hash });
    }
    if (servers.length === 0) {
      while ((m = simpleRe.exec(html)) !== null) {
        if (!seen[m[1]]) { seen[m[1]] = true; servers.push({ name: '', hash: m[1] }); }
      }
    }
    var bodyText = (document.body && document.body.innerText) || '';
    var hasChallenge =
      /just a moment/i.test(document.title) ||
      /cf-chl|cf_chl|checking your browser/i.test(bodyText) ||
      /enable javascript and cookies/i.test(bodyText);
    return JSON.stringify({
      title: document.title || '',
      url: location.href,
      iframeSrc: iframeSrc,
      servers: servers,
      hasChallenge: hasChallenge,
      bodyLen: (document.body && document.body.innerHTML.length) || 0,
      snippet: (bodyText || '').slice(0, 220)
    });
  } catch (e) { return JSON.stringify({ error: String(e) }); }
})();
"""#

private let playerProbeJS = #"""
(function () {
  try {
    var hasPlayButton = !!document.querySelector('#pl_but,.fa-play,[id*=play]');
    var iframeLoaded = !!document.querySelector('iframe[src*="prorcp"], iframe#player_iframe');
    var bodyText = (document.body && document.body.innerText) || '';
    var hasChallenge =
      /just a moment/i.test(document.title) ||
      /cf-chl|cf_chl|checking your browser/i.test(bodyText) ||
      /enable javascript and cookies/i.test(bodyText);
    var hasTurnstile = !!document.querySelector('.cf-turnstile, [data-sitekey]');
    var hasRcpToken = /[?&]_rcp=/.test(location.href);
    return JSON.stringify({
      title: document.title || '',
      url: location.href,
      hasPlayButton: hasPlayButton,
      iframeLoaded: iframeLoaded,
      hasChallenge: hasChallenge,
      hasTurnstile: hasTurnstile,
      hasRcpToken: hasRcpToken,
      bodyLen: (document.body && document.body.innerHTML.length) || 0,
      snippet: (bodyText || '').slice(0, 200)
    });
  } catch (e) { return JSON.stringify({ error: String(e) }); }
})();
"""#

private let clickPlayJS =
    "(function(){var b=document.querySelector('#pl_but,.fa-play,[id*=play]');if(b)b.click();})();"

// Best-effort: scan the top document and any same-origin frames for a <video>
// that has reached its end. Cross-origin frames throw on `.document` access and
// are silently skipped.
private let videoEndedProbeJS = #"""
(function () {
  function check(d) {
    try {
      var vids = d.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var v = vids[i];
        if (v.duration > 0 && (v.ended || v.currentTime >= v.duration - 1.5)) return true;
      }
    } catch (e) {}
    return false;
  }
  var ended = false;
  try { if (check(document)) ended = true; } catch (e) {}
  if (!ended) {
    try {
      for (var i = 0; i < window.frames.length; i++) {
        try { if (window.frames[i].document && check(window.frames[i].document)) { ended = true; break; } } catch (e) {}
      }
    } catch (e) {}
  }
  return JSON.stringify({ ended: ended });
})();
"""#

// MARK: - Resolver controller (owns the WKWebView + state machine)

@MainActor
@Observable
private final class VidsrcResolver: NSObject, WKNavigationDelegate, WKUIDelegate {
    // Poll constants (ported 1:1).
    static let pollAttempts = 14
    static let turnstilePollAttempts = 45
    static let pollIntervalNanos: UInt64 = 700_000_000  // 700ms

    let embedUrls: [URL]

    // Observable UI state
    var status = "Loading embed..."
    var errorMessage: String?
    var lastDiagnostic: String?
    var finishedPlaying = false
    var servers: [VidsrcServer] = []
    var currentServerIndex = 0
    // Best-effort end-of-video detection (only fires when the player's <video>
    // is reachable from JS; cross-origin players never trip it — that's fine, the
    // host falls back to showing recommendations on close).
    var videoEnded = false

    private var domainIndex = 0
    private var stage: VidsrcStage = .embed
    private var cloudnestraBase: URL?
    private var currentTitle = ""
    private var pollTask: Task<Void, Never>?
    private var endWatchTask: Task<Void, Never>?

    let webView: WKWebView

    init(embedUrls: [URL]) {
        self.embedUrls = embedUrls
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Inject the sandbox-defeat guard as early as possible, in EVERY frame
        // (the player iframe lives in a subframe), before any page script runs.
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: unsandboxJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        config.userContentController = controller
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        // NO custom UA (Turnstile) — leave the real WebView UA.
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func start() { loadCurrentDomain() }

    func tearDown() { pollTask?.cancel(); endWatchTask?.cancel() }

    /// Polls the reachable document/frames for an ended <video>. Starts once
    /// playback has begun. No-op (never sets videoEnded) when the player lives in
    /// a cross-origin iframe we can't read.
    private func startEndWatch() {
        endWatchTask?.cancel()
        endWatchTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if self.videoEnded { return }
                guard let text = await self.runJs(videoEndedProbeJS),
                      let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if (json["ended"] as? Bool) == true {
                    self.videoEnded = true
                    return
                }
            }
        }
    }

    // MARK: navigation gating (ported 1:1 from _onNavigationRequest)

    nonisolated func webView(_ webView: WKWebView,
                             decidePolicyFor navigationAction: WKNavigationAction,
                             decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? false
        let url = (navigationAction.request.url?.absoluteString ?? "").lowercased()
        if !isMainFrame { decisionHandler(.allow); return }
        let allow =
            url.hasPrefix("about:") ||
            url.contains("vidsrc-embed") ||
            url.contains("vsembed") ||
            url.contains("vsrc.") ||
            url.contains("vidsrcme") ||
            url.contains("cloudnestra") ||
            url.contains("rcp/") ||
            url.contains("prorcp/")
        decisionHandler(allow ? .allow : .cancel)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in await self.onPageFinished() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.onMainFrameError(error.localizedDescription) }
    }
    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.onMainFrameError(error.localizedDescription) }
    }

    nonisolated func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                             for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        return nil
    }

    // MARK: stage transitions

    private func loadCurrentDomain() {
        pollTask?.cancel()
        if finishedPlaying { return }
        if domainIndex >= embedUrls.count {
            errorMessage = "Could not resolve a working VidSrc server (tried \(embedUrls.count) domain(s)). Tap Retry, or interact with the page directly inside the WebView."
            return
        }
        let url = embedUrls[domainIndex]
        stage = .embed
        servers = []
        currentServerIndex = 0
        cloudnestraBase = nil
        status = "Loading \(url.host ?? "embed")..."
        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    private func nextDomain(error: String?) {
        pollTask?.cancel()
        if finishedPlaying { return }
        domainIndex += 1
        if let error { lastDiagnostic = error }
        loadCurrentDomain()
    }

    private func onMainFrameError(_ desc: String) {
        if stage == .embed { nextDomain(error: "WebView error: \(desc)") }
        else { tryNextServer() }
    }

    private func onPageFinished() async {
        if finishedPlaying { return }
        await injectGuards()
        switch stage {
        case .embed: await waitForEmbed()
        case .player: await onPlayerLoaded()
        case .done: break
        }
    }

    private func injectGuards() async {
        _ = try? await webView.evaluateJavaScript(unsandboxJS)
        _ = try? await webView.evaluateJavaScript(vidsrcGuardJS)
    }

    // MARK: stage 1 — embed page parse

    private func waitForEmbed() async {
        status = "Looking for servers..."
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while !Task.isCancelled {
                if self.finishedPlaying { return }
                attempt += 1
                guard let probe = await self.probeEmbed() else {
                    try? await Task.sleep(nanoseconds: Self.pollIntervalNanos)
                    continue
                }

                if probe.hasChallenge && probe.servers.isEmpty {
                    self.status = "Solving Cloudflare check (\(attempt)s)..."
                    if attempt >= Self.pollAttempts {
                        self.lastDiagnostic = probe.diagnostic
                        self.nextDomain(error: "Cloudflare did not clear on \(self.embedUrls[self.domainIndex].host ?? "").")
                        return
                    }
                    try? await Task.sleep(nanoseconds: Self.pollIntervalNanos)
                    continue
                }

                if !probe.servers.isEmpty && !probe.iframeSrc.isEmpty {
                    self.currentTitle = probe.title
                    self.servers = probe.servers
                    self.currentServerIndex = 0
                    let raw = probe.iframeSrc.hasPrefix("//") ? "https:" + probe.iframeSrc : probe.iframeSrc
                    if let uri = URL(string: raw), let scheme = uri.scheme, let host = uri.host {
                        var comps = URLComponents()
                        comps.scheme = scheme
                        comps.host = host
                        self.cloudnestraBase = comps.url
                    } else {
                        self.cloudnestraBase = URL(string: "https://cloudnestra.com/")
                    }
                    self.navigateToCurrentServer()
                    return
                }

                if attempt >= Self.pollAttempts {
                    self.lastDiagnostic = probe.diagnostic
                    self.nextDomain(error: "No servers visible on \(self.embedUrls[self.domainIndex].host ?? "").")
                    return
                }
                try? await Task.sleep(nanoseconds: Self.pollIntervalNanos)
            }
        }
    }

    private func probeEmbed() async -> EmbedProbe? {
        guard let text = await runJs(embedProbeJS), !text.isEmpty else { return nil }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let list = (json["servers"] as? [Any]) ?? []
        var parsed: [VidsrcServer] = []
        for entry in list {
            guard let e = entry as? [String: Any] else { continue }
            let hash = (e["hash"] as? String) ?? ""
            if hash.isEmpty { continue }
            parsed.append(VidsrcServer(name: (e["name"] as? String) ?? "", hash: hash))
        }
        return EmbedProbe(
            title: (json["title"] as? String) ?? "",
            iframeSrc: (json["iframeSrc"] as? String) ?? "",
            servers: parsed,
            hasChallenge: (json["hasChallenge"] as? Bool) == true,
            diagnostic: "title=\"\(json["title"] ?? "")\", body=\(json["bodyLen"] ?? 0)b, url=\(json["url"] ?? ""), snippet=\"\(json["snippet"] ?? "")\""
        )
    }

    // MARK: stage 2 — cloudnestra /rcp at top level

    private func navigateToCurrentServer() {
        if finishedPlaying { return }
        guard let base = cloudnestraBase else {
            nextDomain(error: "Missing cloudnestra base.")
            return
        }
        if currentServerIndex >= servers.count {
            lastDiagnostic = "All \(servers.count) servers on \(embedUrls[domainIndex].host ?? "") failed."
            nextDomain(error: "No working server on \(embedUrls[domainIndex].host ?? "").")
            return
        }
        let server = servers[currentServerIndex]
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            nextDomain(error: "Bad cloudnestra base.")
            return
        }
        comps.path = "/rcp/\(server.hash)"
        guard let url = comps.url else { nextDomain(error: "Bad rcp URL."); return }
        stage = .player
        status = "Loading \(server.name.isEmpty ? "server \(currentServerIndex + 1)" : server.name)..."
        webView.load(URLRequest(url: url))
    }

    private func onPlayerLoaded() async {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 0
            while !Task.isCancelled {
                if self.finishedPlaying { return }
                attempt += 1
                guard let probe = await self.probePlayer() else {
                    try? await Task.sleep(nanoseconds: Self.pollIntervalNanos)
                    continue
                }

                if probe.hasChallenge {
                    self.status = "Cloudflare check on cloudnestra (\(attempt)s)..."
                    if attempt >= Self.pollAttempts {
                        self.lastDiagnostic = probe.diagnostic
                        self.tryNextServer()
                        return
                    }
                    try? await Task.sleep(nanoseconds: Self.pollIntervalNanos)
                    continue
                }

                if probe.hasTurnstile && !probe.hasRcpToken {
                    self.status = "Verifying with Cloudflare Turnstile (\(attempt)s)..."
                    if attempt >= Self.turnstilePollAttempts {
                        self.lastDiagnostic = probe.diagnostic
                        self.tryNextServer()
                        return
                    }
                    try? await Task.sleep(nanoseconds: Self.pollIntervalNanos)
                    continue
                }

                if probe.hasPlayButton && !probe.iframeLoaded {
                    _ = await self.runJs(clickPlayJS)
                }

                if probe.hasPlayButton || probe.iframeLoaded {
                    self.finishedPlaying = true
                    self.status = probe.iframeLoaded
                        ? "Playing in WebView. Tap inside the player area if it pauses."
                        : "Server ready — tap the play button in the player."
                    self.startEndWatch()
                    return
                }

                if attempt >= Self.pollAttempts {
                    self.lastDiagnostic = probe.diagnostic
                    self.tryNextServer()
                    return
                }
                try? await Task.sleep(nanoseconds: Self.pollIntervalNanos)
            }
        }
    }

    private func probePlayer() async -> PlayerProbe? {
        guard let text = await runJs(playerProbeJS) else { return nil }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return PlayerProbe(
            hasPlayButton: (json["hasPlayButton"] as? Bool) == true,
            iframeLoaded: (json["iframeLoaded"] as? Bool) == true,
            hasChallenge: (json["hasChallenge"] as? Bool) == true,
            hasTurnstile: (json["hasTurnstile"] as? Bool) == true,
            hasRcpToken: (json["hasRcpToken"] as? Bool) == true,
            diagnostic: "cloudnestra: title=\"\(json["title"] ?? "")\", body=\(json["bodyLen"] ?? 0)b, playBtn=\(json["hasPlayButton"] ?? false), iframe=\(json["iframeLoaded"] ?? false), turnstile=\(json["hasTurnstile"] ?? false), rcp=\(json["hasRcpToken"] ?? false), url=\(json["url"] ?? ""), snippet=\"\(json["snippet"] ?? "")\""
        )
    }

    private func tryNextServer() {
        pollTask?.cancel()
        currentServerIndex += 1
        navigateToCurrentServer()
    }

    func switchToServer(_ index: Int) {
        guard index >= 0, index < servers.count else { return }
        pollTask?.cancel()
        finishedPlaying = false
        currentServerIndex = index
        status = "Loading \(servers[index].name.isEmpty ? "server \(index + 1)" : servers[index].name)..."
        navigateToCurrentServer()
    }

    func retry() {
        domainIndex = 0
        errorMessage = nil
        lastDiagnostic = nil
        loadCurrentDomain()
    }

    // MARK: JS bridge

    private func runJs(_ js: String) async -> String? {
        do {
            let raw = try await webView.evaluateJavaScript(js)
            if let s = raw as? String { return s }
            if raw is NSNull { return nil }
            return "\(raw)"
        } catch {
            return nil
        }
    }
}

// MARK: - WKWebView host

private struct VidsrcWebHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - VidsrcResolveScreen (public)

struct VidsrcResolveScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    private let item: MediaItem

    // Mutable so autoplay can swap this screen onto the next VidSrc episode.
    @State private var title: String
    @State private var episode: MediaEpisode?
    @State private var resolver: VidsrcResolver

    // End-of-show recommendations / autoplay handoff.
    @State private var recommendations: [MediaItem]? = nil
    @State private var loadingRecommendations = false
    @State private var nextPlayer: PlayerRoute? = nil
    @State private var recommendationDetail: MediaItem? = nil
    @State private var handledFinish = false

    init(item: MediaItem, title: String, embedUrls: [URL], episode: MediaEpisode? = nil) {
        self.item = item
        _title = State(initialValue: title)
        _episode = State(initialValue: episode)
        _resolver = State(initialValue: VidsrcResolver(embedUrls: embedUrls))
    }

    /// Best-effort end detected (or manual close on a movie): autoplay the next
    /// episode if there is one, otherwise show recommendations.
    private func handleFinished() {
        guard !handledFinish else { return }
        handledFinish = true
        Task {
            if let next = await AutoplayResolver.resolveNext(item: item, episode: episode, appState: appState) {
                switch next {
                case .player(let r):
                    nextPlayer = r
                case .vidsrc(let v):
                    episode = v.episode
                    title = v.title
                    resolver.tearDown()
                    let fresh = VidsrcResolver(embedUrls: v.embedUrls)
                    resolver = fresh
                    handledFinish = false
                    fresh.start()
                }
                return
            }
            loadingRecommendations = true
            let recs = await appState.recommendationsFor(item)
            loadingRecommendations = false
            if recs.isEmpty { dismiss() } else { recommendations = recs }
        }
    }

    /// Movies show recommendations on close (fallback when end-detection didn't
    /// fire); everything else just closes.
    private func closeOrRecommend() {
        if resolver.finishedPlaying, episode == nil, recommendations == nil, !loadingRecommendations, !handledFinish {
            handleFinished()
        } else {
            dismiss()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: close, title, server switcher.
            HStack {
                Button { closeOrRecommend() } label: {
                    Image(systemName: "xmark").foregroundStyle(.white).padding(8)
                }.buttonStyle(.plain)

                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)

                if resolver.servers.count > 1 {
                    Menu {
                        ForEach(Array(resolver.servers.enumerated()), id: \.offset) { i, server in
                            Button {
                                resolver.switchToServer(i)
                            } label: {
                                Text(server.name.isEmpty ? "Server \(i + 1)" : server.name)
                                if i == resolver.currentServerIndex { Image(systemName: "checkmark") }
                            }
                        }
                    } label: {
                        Image(systemName: "rectangle.stack").foregroundStyle(.white).padding(8)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.top, 6)

            // Status / diagnostic line.
            if !resolver.finishedPlaying {
                HStack(spacing: 10) {
                    if resolver.errorMessage == nil {
                        ProgressView().scaleEffect(0.8).tint(.white)
                    }
                    Text(resolver.errorMessage ?? resolver.status)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The WebView IS the player. Always visible.
            VidsrcWebHost(webView: resolver.webView)
                .background(Color.black)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Error footer with diagnostic + Retry/Close.
            if resolver.errorMessage != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if let diag = resolver.lastDiagnostic {
                        Text(diag).font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.62)).lineLimit(5)
                    }
                    HStack(spacing: 10) {
                        Button { resolver.retry() } label: {
                            Label("Retry", systemImage: "arrow.clockwise").foregroundStyle(.white)
                        }
                        .buttonStyle(.bordered).tint(.white)
                        Button("Close") { dismiss() }.foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.86))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .keepScreenAwake(true)
        .onAppear {
            PlayerOrientation.forceLandscape()
            resolver.start()
        }
        .onDisappear {
            PlayerOrientation.restore()
            resolver.tearDown()
        }
        .onChange(of: resolver.videoEnded) { _, ended in
            if ended { handleFinished() }
        }
        .overlay {
            if recommendations != nil || loadingRecommendations {
                RecommendationsEndOverlay(
                    showTitle: item.title,
                    recommendations: recommendations,
                    loading: loadingRecommendations,
                    onSelect: { recommendationDetail = $0 },
                    onClose: { dismiss() })
            }
        }
        // Next episode resolved to a direct stream — hand off to the native player.
        .fullScreenCover(item: $nextPlayer) { r in
            PlayerScreen(title: r.title, url: r.url, headers: r.headers, item: r.item, episode: r.episode,
                         subtitleUrl: r.subtitleUrl, startPositionMs: r.startPositionMs, aniSkipEpisode: r.aniSkipEpisode)
        }
        // A recommended title opens its own detail screen.
        .fullScreenCover(item: $recommendationDetail) { rec in
            MediaDetailScreen(item: rec)
        }
    }
}
